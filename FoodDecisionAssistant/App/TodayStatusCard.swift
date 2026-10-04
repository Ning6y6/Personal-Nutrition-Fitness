import FoodDecisionCore
import SwiftUI

struct TodayStatusCard: View {
    let goal: GoalProfile?
    let nutrients: NutrientValues
    let mealCount: Int

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("今日摄入")
                    .font(.headline)
                Text("\(mealCount) 餐已记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if let goal {
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
                    unit: "g"
                )
                NutritionProgressRow(
                    title: "碳水",
                    current: nutrients.carbohydrateGrams,
                    target: goal.carbohydrateGrams,
                    unit: "g"
                )
                NutritionProgressRow(
                    title: "脂肪",
                    current: nutrients.fatGrams,
                    target: goal.fatGrams,
                    unit: "g"
                )

                if let saturatedFatTarget = goal.saturatedFatLimitGrams {
                    NutritionProgressRow(
                        title: "饱和脂肪",
                        current: nutrients.saturatedFatGrams,
                        target: saturatedFatTarget,
                        unit: "g",
                        isUpperLimit: true
                    )
                }

                if let fibreTarget = goal.fibreGrams {
                    if let fibre = nutrients.fibreGrams {
                        NutritionProgressRow(
                            title: "纤维",
                            current: fibre,
                            target: fibreTarget,
                            unit: "g"
                        )
                    } else {
                        LabeledContent("纤维", value: "当日数据不完整")
                            .font(.subheadline)
                    }
                }
            } else {
                Label("尚未设置每日目标", systemImage: "target")
                    .font(.headline)
                Text("设置目标后，这里会显示热量圆环和营养缺口。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    TodayStatusCard(
        goal: GoalProfile(
            energyKcal: 2_000,
            proteinGrams: 140,
            carbohydrateGrams: 210,
            fatGrams: 60,
            saturatedFatLimitGrams: 15,
            fibreGrams: 30
        ),
        nutrients: NutrientValues(
            energyKcal: 1_420,
            fatGrams: 42,
            saturatedFatGrams: 8,
            carbohydrateGrams: 150,
            sugarGrams: 20,
            proteinGrams: 96,
            saltGrams: 3,
            fibreGrams: 18
        ),
        mealCount: 2
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
