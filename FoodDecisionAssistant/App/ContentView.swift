import FoodDecisionCore
import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \PersistentGoalProfile.effectiveFrom, order: .reverse)
    private var goalProfiles: [PersistentGoalProfile]

    @State private var isShowingGoalSettings = false

    private var currentGoal: GoalProfile? {
        goalProfiles.first?.domainModel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TodayStatusCard(goal: currentGoal)
                    HomeActionCard(
                        title: "记录一餐",
                        subtitle: "称重录入家常菜，或使用外卖估算模板",
                        systemImage: "fork.knife"
                    )
                    HomeActionCard(
                        title: "扫描食品标签",
                        subtitle: "先检查硬约束，再计算营养分",
                        systemImage: "viewfinder"
                    )
                    HomeActionCard(
                        title: "待核对",
                        subtitle: "补齐未识别字段后再给正式结论",
                        systemImage: "checklist"
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("目标") {
                        isShowingGoalSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingGoalSettings) {
                GoalSettingsView()
            }
        }
    }
}

private struct TodayStatusCard: View {
    let goal: GoalProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("第一阶段工程已启动")
                .font(.headline)
            Text("当前目标：完成可校正的饮食记录闭环")
                .foregroundStyle(.secondary)
            ProgressView(value: 0.15)
                .tint(.green)
            HStack {
                Label(energyLabel, systemImage: "flame")
                Spacer()
                Text("规则 v1")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var energyLabel: String {
        guard let goal else {
            return "尚未设置每日目标"
        }

        return "目标 \(goal.energyKcal.formatted(.number.precision(.fractionLength(0)))) kcal"
    }
}

private struct HomeActionCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(
                    Color.green.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
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

private struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PersistentGoalProfile.effectiveFrom, order: .reverse)
    private var goalProfiles: [PersistentGoalProfile]

    @State private var energyKcal = 2_000.0
    @State private var proteinGrams = 140.0
    @State private var carbohydrateGrams = 210.0
    @State private var fatGrams = 60.0
    @State private var saturatedFatLimitGrams = 15.0
    @State private var fibreGrams = 30.0
    @State private var saveError: Error?

    var body: some View {
        NavigationStack {
            Form {
                GoalEnergySection(energyKcal: $energyKcal)
                GoalMacrosSection(
                    proteinGrams: $proteinGrams,
                    carbohydrateGrams: $carbohydrateGrams,
                    fatGrams: $fatGrams
                )
                GoalLimitsSection(
                    saturatedFatLimitGrams: $saturatedFatLimitGrams,
                    fibreGrams: $fibreGrams
                )
            }
            .navigationTitle("每日目标")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveGoal()
                    }
                }
            }
            .task(id: goalProfiles.first?.id) {
                loadGoal()
            }
            .alert(
                "无法保存目标",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError?.localizedDescription ?? "")
            }
        }
    }

    private func loadGoal() {
        guard let goal = goalProfiles.first?.domainModel else {
            return
        }

        energyKcal = goal.energyKcal
        proteinGrams = goal.proteinGrams
        carbohydrateGrams = goal.carbohydrateGrams
        fatGrams = goal.fatGrams
        saturatedFatLimitGrams = goal.saturatedFatLimitGrams ?? 0
        fibreGrams = goal.fibreGrams ?? 0
    }

    private func saveGoal() {
        let domain = GoalProfile(
            id: goalProfiles.first?.id ?? UUID(),
            effectiveFrom: goalProfiles.first?.effectiveFrom ?? .now,
            energyKcal: energyKcal,
            proteinGrams: proteinGrams,
            carbohydrateGrams: carbohydrateGrams,
            fatGrams: fatGrams,
            saturatedFatLimitGrams: saturatedFatLimitGrams,
            fibreGrams: fibreGrams
        )

        if let persistentGoal = goalProfiles.first {
            persistentGoal.update(from: domain)
        } else {
            modelContext.insert(PersistentGoalProfile(domain: domain))
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error
        }
    }
}

private struct GoalEnergySection: View {
    @Binding var energyKcal: Double

    var body: some View {
        Section("能量") {
            TextField("每日热量 (kcal)", value: $energyKcal, format: .number)
                .keyboardType(.decimalPad)
        }
    }
}

private struct GoalMacrosSection: View {
    @Binding var proteinGrams: Double
    @Binding var carbohydrateGrams: Double
    @Binding var fatGrams: Double

    var body: some View {
        Section("宏量营养素 (g)") {
            TextField("蛋白质", value: $proteinGrams, format: .number)
                .keyboardType(.decimalPad)
            TextField("碳水化合物", value: $carbohydrateGrams, format: .number)
                .keyboardType(.decimalPad)
            TextField("脂肪", value: $fatGrams, format: .number)
                .keyboardType(.decimalPad)
        }
    }
}

private struct GoalLimitsSection: View {
    @Binding var saturatedFatLimitGrams: Double
    @Binding var fibreGrams: Double

    var body: some View {
        Section("限制与目标 (g)") {
            TextField("饱和脂肪上限", value: $saturatedFatLimitGrams, format: .number)
                .keyboardType(.decimalPad)
            TextField("纤维目标", value: $fibreGrams, format: .number)
                .keyboardType(.decimalPad)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
}
