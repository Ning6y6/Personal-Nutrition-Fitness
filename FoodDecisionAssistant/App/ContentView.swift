import FoodDecisionCore
import SwiftUI

struct ContentView: View {
    private let goal = GoalProfile(
        energyKcal: 2_000,
        proteinGrams: 140,
        carbohydrateGrams: 210,
        fatGrams: 60,
        saturatedFatLimitGrams: 15,
        fibreGrams: 30
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    actionCard(
                        title: "记录一餐",
                        subtitle: "称重录入家常菜，或使用外卖估算模板",
                        systemImage: "fork.knife"
                    )
                    actionCard(
                        title: "扫描食品标签",
                        subtitle: "先检查硬约束，再计算营养分",
                        systemImage: "viewfinder"
                    )
                    actionCard(
                        title: "待核对",
                        subtitle: "补齐未识别字段后再给正式结论",
                        systemImage: "checklist"
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("今日")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("第一阶段工程已启动")
                .font(.headline)
            Text("当前目标：完成可校正的饮食记录闭环")
                .foregroundStyle(.secondary)
            ProgressView(value: 0.15)
                .tint(.green)
            HStack {
                Label("目标 \(Int(goal.energyKcal)) kcal", systemImage: "flame")
                Spacer()
                Text("规则 v1")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func actionCard(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    ContentView()
}

