import FoodDecisionCore
import SwiftUI

enum NutritionDisplayTone: Equatable, Sendable {
    case neutral, success, warning, danger

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .success: DesignTokens.accent
        case .warning, .danger: DesignTokens.warningText
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
        // v1 remains readable, but even legacy nutrition must not use hard-constraint red.
        switch summary.displayTone {
        case .neutral: tone = .neutral
        case .theme: tone = .success
        case .amber: tone = .warning
        case .critical: tone = .danger
        }
        switch summary.status {
        case .belowMinimum:
            message = "距最低目标还差 \(remaining) \(unit)"
            symbol = "circle.dotted"
        case .minimumMet:
            message = "已达最低目标"
            symbol = "checkmark.circle.fill"
        case .withinBudget:
            message = "预算剩余 \(remaining) \(unit)"
            symbol = "circle.dotted"
        case .atBudget:
            message = "已达到预算，尚未超出"
            symbol = "checkmark.circle.fill"
        case .overBudget:
            message = "超出预算 \(overage) \(unit)"
            symbol = "exclamationmark.circle.fill"
        case .significantlyOverBudget:
            message = summary.policyVersion == 1 ? "明显超出预算 \(overage) \(unit)" : "超出预算 \(overage) \(unit)"
            symbol = summary.policyVersion == 1 ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
        case .belowMaximum:
            message = "距上限剩余 \(remaining) \(unit)"
            symbol = "circle.dotted"
        case .approachingMaximum:
            message = "接近上限，剩余 \(remaining) \(unit)"
            symbol = "exclamationmark.circle.fill"
        case .atMaximum:
            message = "已到上限，尚未超出"
            symbol = "exclamationmark.circle.fill"
        case .overMaximum:
            message = "已超出上限 \(overage) \(unit)"
            symbol = "exclamationmark.triangle.fill"
        case .unset:
            message = "未设置\(Self.goalTerm(summary.semantics))"
            symbol = "target"
        case .unavailable:
            message = "摄入数据未提供，无法计算缺口"
            symbol = "questionmark.circle"
        case .invalidInput:
            message = "数据无效，无法计算进度"
            symbol = "exclamationmark.triangle"
        }
    }

    private static func goalTerm(_ semantics: NutritionGoalSemantics) -> String {
        switch semantics {
        case .minimum: "目标"
        case .budget: "预算"
        case .maximum: "上限"
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
