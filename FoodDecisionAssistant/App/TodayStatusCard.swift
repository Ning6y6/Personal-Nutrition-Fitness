import FoodDecisionCore
import SwiftUI

struct TodayStatusCard: View {
    let goal: GoalProfile?
    let nutrients: NutrientValues?
    let mealCount: Int
    let fibreSummary: FibreIntakeSummary?
    let availability: MealIntakeAvailability
    var hasGoalReadError = false

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("今日已记录摄入")
                    .font(.headline)
                Text("\(mealCount) 餐计入合计")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if hasGoalReadError {
                Label("已保存目标暂不可用", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text("无法读取或校验目标，请到目标页检查。原数据保留，未按无目标或零目标计算。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !availability.canShowNutritionProgress {
                EmptyIntakeSummaryView(
                    availability: availability,
                    goal: hasGoalReadError ? nil : goal
                )
            } else if !hasGoalReadError, let nutrients, let goal {
                EnergyProgressRing(
                    consumedKcal: nutrients.energyKcal,
                    targetKcal: goal.energyKcal
                )
                .frame(maxWidth: 180)
                .frame(maxWidth: .infinity)

                NutritionProgressRow(
                    title: "蛋白质",
                    current: nutrients.proteinGrams,
                    target: goal.proteinGrams,
                    unit: "g",
                    metric: .protein
                )
                NutritionProgressRow(
                    title: "碳水",
                    current: nutrients.carbohydrateGrams,
                    target: goal.carbohydrateGrams,
                    unit: "g",
                    metric: .carbohydrate
                )
                NutritionProgressRow(
                    title: "脂肪",
                    current: nutrients.fatGrams,
                    target: goal.fatGrams,
                    unit: "g",
                    metric: .fat
                )

                NutritionProgressRow(
                    title: "饱和脂肪",
                    current: nutrients.saturatedFatGrams,
                    target: goal.saturatedFatLimitGrams,
                    unit: "g",
                    metric: .saturatedFat
                )
            } else if !hasGoalReadError, nutrients == nil {
                Label("营养合计无法安全计算", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text("未显示零摄入。请在历史记录中检查并修复异常数据。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !hasGoalReadError {
                Label("尚未设置每日目标", systemImage: "target")
                    .font(.headline)
                Text("设置目标后，这里会显示热量圆环和营养缺口。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if availability == .available || availability == .unavailable {
                FibreSummaryRow(
                    summary: fibreSummary, target: goal?.fibreGrams,
                    showsTarget: availability.canShowNutritionProgress && goal != nil && !hasGoalReadError
                )
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    if let goal = try? GoalProfile(
        energyKcal: 2_000, proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60,
        saturatedFatLimitGrams: 15, fibreGrams: 30
    ), let nutrients = try? NutrientValues(
        energyKcal: 1_420, fatGrams: 42, saturatedFatGrams: 8, carbohydrateGrams: 150,
        sugarGrams: 20, proteinGrams: 96, saltGrams: 3, fibreGrams: 18
    ) {
        TodayStatusCard(
            goal: goal,
            nutrients: nutrients,
            mealCount: 2,
            fibreSummary: try? FibreIntakeSummary(snapshots: [nutrients]),
            availability: .available
        )
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
