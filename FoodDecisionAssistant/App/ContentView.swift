import FoodDecisionCore
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PersistentGoalProfile.effectiveFrom, order: .reverse)
    private var goalProfiles: [PersistentGoalProfile]

    @Query(sort: \PersistentMealLog.eatenAt, order: .reverse)
    private var mealLogs: [PersistentMealLog]

    @State private var isShowingGoalSettings = false
    @State private var isShowingMealStart = false
    @State private var isShowingMealHistory = false
    @State private var isShowingBackup = false
    @State private var selectedMeal: PersistentMealLog?
    @State private var seedImportError: Error?

    private var currentGoal: GoalProfile? {
        try? goalProfiles.first?.domainModel
    }

    private var todayMeals: [PersistentMealLog] {
        mealLogs.filter { Calendar.current.isDateInToday($0.eatenAt) }
    }

    private var todaySummary: MealReadValidation {
        MealReadValidation(todayMeals)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    let summary = todaySummary
                    TodayStatusCard(
                        goal: currentGoal,
                        nutrients: summary.nutrients,
                        mealCount: summary.meals.count
                    )
                    if !summary.invalidRecordIDs.isEmpty || !summary.draftRecordIDs.isEmpty {
                        Label(
                            "今日有\(summary.invalidRecordIDs.count)条旧记录需修复、\(summary.draftRecordIDs.count)条未确认草稿，未计入正式汇总。原记录仍在历史中。",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    }
                    if !goalProfiles.isEmpty && currentGoal == nil {
                        Label("已保存目标含无效数据，请到目标页检查；原数据保留。", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    Button {
                        isShowingMealStart = true
                    } label: {
                        HomeActionCard(
                            title: "记录一餐",
                            subtitle: "称重录入家常菜，或使用标准份量估算",
                            systemImage: "fork.knife",
                            isAvailable: true
                        )
                    }
                    .buttonStyle(.plain)
                    RecentMealsCard(
                        meals: Array(todayMeals.prefix(3)),
                        hasHistory: !mealLogs.isEmpty,
                        selectMeal: { selectedMeal = $0 },
                        showHistory: { isShowingMealHistory = true }
                    )
                    HomeActionCard(
                        title: "扫描食品标签",
                        subtitle: "先检查硬约束，再计算营养分",
                        systemImage: "viewfinder",
                        isAvailable: false
                    )
                    HomeActionCard(
                        title: "待核对",
                        subtitle: "补齐未识别字段后再给正式结论",
                        systemImage: "checklist",
                        isAvailable: false
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("本地备份", systemImage: "externaldrive") {
                        isShowingBackup = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("目标") {
                        isShowingGoalSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingGoalSettings) {
                GoalSettingsView()
            }
            .sheet(isPresented: $isShowingBackup) {
                BackupManagementView()
            }
            .sheet(isPresented: $isShowingMealStart) {
                MealStartView()
            }
            .sheet(isPresented: $isShowingMealHistory) {
                MealHistoryView()
            }
            .sheet(item: $selectedMeal) { meal in
                MealDetailView(meal: meal)
            }
            .task {
                do {
                    try SeedFoodCatalog.importIfNeeded(into: modelContext)
                } catch {
                    seedImportError = error
                }
            }
            .alert(
                "无法准备食物库",
                isPresented: Binding(
                    get: { seedImportError != nil },
                    set: { if !$0 { seedImportError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(seedImportError?.localizedDescription ?? "")
            }
        }
    }
}

private struct RecentMealsCard: View {
    let meals: [PersistentMealLog]
    let hasHistory: Bool
    let selectMeal: (PersistentMealLog) -> Void
    let showHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日记录")
                .font(.headline)

            if meals.isEmpty {
                Text("今天还没有记录餐食。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    if index > 0 {
                        Divider()
                    }
                    Button {
                        selectMeal(meal)
                    } label: {
                        MealSummaryRow(meal: meal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("查看、编辑或删除这条餐食记录")
                }
            }

            if hasHistory {
                Divider()
                Button("查看全部历史", systemImage: "clock.arrow.circlepath") {
                    showHistory()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct HomeActionCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let isAvailable: Bool

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
            if isAvailable {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            } else {
                Text("开发中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        guard let goal = try? goalProfiles.first?.domainModel else {
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
        do {
            let domain = try GoalProfile(
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

            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
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
