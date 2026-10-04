import FoodDecisionCore
import SwiftUI

enum NutritionDisplayTone: Equatable, Sendable {
    case neutral, success, warning, danger

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        case .danger: .red
        }
    }
}

/// Presentation only: thresholds, validity, progress and quantities come from Core.
/// Keeping text, symbol and tone together prevents contradictory warning treatments.
struct NutritionProgressPresentation: Equatable, Sendable {
    let currentText: String
    let targetText: String
    let valueLabel: String
    let message: String
    let symbol: String
    let tone: NutritionDisplayTone
    let progress: Double?

    init(summary: NutritionProgressSummary, unit: String) {
        currentText = summary.consumed.map(Self.formatted) ?? "—"
        targetText = summary.target.map(Self.formatted) ?? "—"
        valueLabel = "\(currentText) / \(targetText) \(unit)"
        progress = summary.progress
        let remaining = summary.remaining.map(Self.formatted) ?? "—"
        let overage = summary.overage.map(Self.formatted) ?? "—"
        switch summary.status {
        case .belowMinimum:
            message = "距最低目标还差 \(remaining) \(unit)"
            symbol = "circle.dotted"
            tone = .neutral
        case .minimumMet:
            message = "已达最低目标"
            symbol = "checkmark.circle.fill"
            tone = .success
        case .withinBudget:
            message = "预算剩余 \(remaining) \(unit)"
            symbol = "circle.dotted"
            tone = .success
        case .atBudget:
            message = "已达到预算"
            symbol = "checkmark.circle.fill"
            tone = .success
        case .overBudget:
            message = "超出预算 \(overage) \(unit)"
            symbol = "exclamationmark.circle.fill"
            tone = .warning
        case .significantlyOverBudget:
            message = "明显超出预算 \(overage) \(unit)"
            symbol = "exclamationmark.triangle.fill"
            tone = .danger
        case .belowMaximum:
            message = "距上限剩余 \(remaining) \(unit)"
            symbol = "circle.dotted"
            tone = .success
        case .approachingMaximum:
            message = "接近上限，剩余 \(remaining) \(unit)"
            symbol = "exclamationmark.circle.fill"
            tone = .warning
        case .atMaximum:
            message = "已到上限，尚未超出"
            symbol = "exclamationmark.circle.fill"
            tone = .warning
        case .overMaximum:
            message = "已超出上限 \(overage) \(unit)"
            symbol = "exclamationmark.triangle.fill"
            tone = .danger
        case .unset:
            message = "未设置目标"
            symbol = "target"
            tone = .neutral
        case .unavailable:
            message = "摄入数据未提供，无法计算缺口"
            symbol = "questionmark.circle"
            tone = .neutral
        case .invalidInput:
            message = "数据无效，无法计算进度"
            symbol = "exclamationmark.triangle"
            tone = .neutral
        }
    }

    private static func formatted(_ value: Double) -> String {
        // A small positive overage must not become the contradictory warning "超出 0".
        if value > 0, value < 0.1 {
            return "不足 \(0.1.formatted(.number.precision(.fractionLength(1))))"
        }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
