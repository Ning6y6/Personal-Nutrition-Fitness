import FoodDecisionCore
import SwiftUI

struct TodayStatusPreview: View {
    let scenario: UI1PreviewScenario

    var body: some View {
        if let goal = try? scenario.goal(), let nutrients = try? scenario.nutrients() {
            TodayStatusCard(
                goal: goal,
                nutrients: scenario == .empty || scenario == .unknown ? nil : nutrients,
                mealCount: scenario == .empty ? 0 : 2,
                fibreSummary: scenario == .empty || scenario == .unknown ? nil : try? FibreIntakeSummary(snapshots: [nutrients]),
                availability: scenario == .empty ? .noRecords : scenario == .unknown ? .unavailable : .available
            )
            .padding()
            .background(DesignTokens.background)
            .tint(DesignTokens.accent)
        }
    }
}

#Preview("今日 · 浅色") {
    TodayStatusPreview(scenario: .withinBudget)
}

#Preview("今日 · 深色") {
    TodayStatusPreview(scenario: .withinBudget).preferredColorScheme(.dark)
}

#Preview("空态 · 浅色") {
    TodayStatusPreview(scenario: .empty)
}

#Preview("空态 · 深色") {
    TodayStatusPreview(scenario: .empty).preferredColorScheme(.dark)
}

#Preview("空态 · 最大辅助字体") {
    ScrollView {
        TodayStatusPreview(scenario: .empty)
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("空态 · 未设置预算") {
    TodayStatusCard(goal: nil, nutrients: nil, mealCount: 0, fibreSummary: nil, availability: .noRecords)
        .padding()
        .background(DesignTokens.background)
}

#Preview("达到预算") {
    TodayStatusPreview(scenario: .atBudget)
}

#Preview("超出预算 · 浅色") {
    TodayStatusPreview(scenario: .overflow)
}

#Preview("3.2倍 · 深色") {
    TodayStatusPreview(scenario: .multiple).preferredColorScheme(.dark)
}

#Preview("最大辅助字体 · 超出") {
    ScrollView {
        TodayStatusPreview(scenario: .multiple)
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("数据不可用") {
    TodayStatusPreview(scenario: .unknown)
}
