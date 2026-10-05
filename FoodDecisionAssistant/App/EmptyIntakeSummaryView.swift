import FoodDecisionCore
import SwiftUI

/// Neutral unavailable-intake state. Saved targets remain readable without implying that
/// missing meal records are zero intake, under budget, or a completed dietary target.
struct EmptyIntakeSummaryView: View {
    let availability: MealIntakeAvailability
    let goal: GoalProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(availability.title, systemImage: availability.symbol)
                .font(.headline)
            Text(availability.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let goal {
                Divider()
                DisclosureGroup("查看已保存目标") {
                    Text("尚未计算摄入进度")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LabeledContent("热量预算", value: "\(formatted(goal.energyKcal)) kcal")
                    LabeledContent("蛋白质最低目标", value: "\(formatted(goal.proteinGrams)) g")
                    LabeledContent("碳水预算", value: "\(formatted(goal.carbohydrateGrams)) g")
                    LabeledContent("脂肪预算", value: "\(formatted(goal.fatGrams)) g")
                    LabeledContent("饱和脂肪上限", value: goal.saturatedFatLimitGrams.map { "\(formatted($0)) g" } ?? "未设置")
                    LabeledContent("纤维最低目标", value: goal.fibreGrams.map { "\(formatted($0)) g" } ?? "未设置")
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        FibreSummaryPresentation.formatted(value)
    }
}
