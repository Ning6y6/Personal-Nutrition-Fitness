import FoodDecisionCore
import Foundation

/// Text for the two-lap graphic. No calculation or color threshold lives in the view.
struct EnergyRingPresentation: Equatable, Sendable {
    let nutrition: NutritionProgressPresentation
    let message: String

    init(summary: EnergyProgressSummary) {
        nutrition = NutritionProgressPresentation(summary: summary.nutritionProgress, unit: "kcal")
        if summary.ratioIsSaturated {
            // A saturated finite ratio is not exact; rounding its lower bound up is misleading.
            message = "\(nutrition.message) · 倍数超出可显示精度"
        } else if let multiple = summary.multiple, multiple >= 2 {
            let ratioText = multiple >= 1_000_000
                ? multiple.formatted(.number.notation(.scientific).precision(.significantDigits(1...3)))
                : multiple.formatted(.number.precision(.fractionLength(0...1)))
            message = "\(nutrition.message) · 约为预算的 \(ratioText) 倍"
        } else {
            message = nutrition.message
        }
    }
}
